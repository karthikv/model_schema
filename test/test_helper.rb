$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'model_schema'

require 'minitest/autorun'
require 'minitest/hooks/test'

class BaseTest < Minitest::Test
  include Minitest::Hooks

  def error_class
    ModelSchema::SchemaError
  end

  def type_extra
    ModelSchema::SchemaError::TYPE_EXTRA
  end

  def type_missing
    ModelSchema::SchemaError::TYPE_MISSING
  end

  def type_mismatch
    ModelSchema::SchemaError::TYPE_MISMATCH
  end

  def field_columns
    ModelSchema::FIELD_COLUMNS
  end

  def find_match(array, condition)
    array.find do |elem|
      condition.keys.all? do |key|
        condition[key] == elem[key]
      end
    end
  end

  def create_diff(field, type, opts)
    opts.merge(:field => field, :type => type)
  end

  def create_extra_diff(field, generator, condition)
    elem = find_match(generator.send(field), condition)
    create_diff(field, type_extra, :generator => generator, :elem => elem)
  end

  def create_missing_diff(field, generator, condition)
    elem = find_match(generator.send(field), condition)
    create_diff(field, type_missing, :generator => generator, :elem => elem)
  end

  def create_mismatch_diff(field, db_generator, exp_generator, condition)
    db_elem = find_match(db_generator.send(field), condition)
    exp_elem = find_match(exp_generator.send(field), condition)

    create_diff(field, type_mismatch, :db_generator => db_generator,
                                      :exp_generator => exp_generator,
                                      :db_elem => db_elem,
                                      :exp_elem => exp_elem)
  end
end
