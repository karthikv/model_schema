require 'bundler/setup'

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'model_schema'

require 'minitest/autorun'
require 'minitest/hooks/test'
require 'mocha/mini_test'

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

  def field_indexes
    ModelSchema::FIELD_INDEXES
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

  def schema_error(schema_diffs=[])
    ModelSchema::SchemaError.new(@table_name, schema_diffs)
  end

  def dump_column(generator, name)
    schema_error.dump_single(field_columns, generator,
                             find_match(generator.columns, :name => name))
  end

  def dump_index(generator, columns)
    columns = columns.is_a?(Array) ? columns : [columns]
    schema_error.dump_single(field_indexes, generator,
                             find_match(generator.indexes, :columns => columns))
  end

  def assert_includes_with_order(message, parts)
    parts.each do |part|
      if part.is_a?(String)
        assert_includes message, part
        index = message.index(part)
        message = message[(index + part.length)..-1]
      else
        # part is an array of strings, each of which must be included in
        # message, but in any order with respect to one another
        pieces = part
        end_index = 0

        pieces.each do |p|
          assert_includes message, p
          cur_end_index = message.index(p) + p.length
          end_index = [end_index, cur_end_index].max
        end

        message = message[end_index..-1]
      end
    end
  end

  def create_simple_table(db)
    table_name = :simple
    db.create_table(table_name) do
      String :name, :size => 50
      Integer :value, :null => false
      index :name, :unique => true
    end

    table_name
  end

  def create_complex_table(db)
    # other table for referencing
    db.create_table(:others) do
      primary_key :id
      Integer :value
    end

    table_name = :complex
    db.create_table(table_name) do
      primary_key :id
      foreign_key :other_id, :others, :null => false, :on_delete => :cascade

      String :name
      String :location, :fixed => true, :size => 50
      String :legal_name, :size => 200
      String :advisor, :text => true

      BigDecimal :amount, :size => 10
      Integer :value, :null => false, :unique => true

      column :advisors, 'varchar(255)[]', :null => false
      column :interests, 'text[]', :null => false, :index => {:name => :int_index}

      TrueClass :is_right

      Time :created_at, :null => false
      Time :updated_at, :only_time => true

      index [:other_id, :name]
    end

    table_name
  end
end
