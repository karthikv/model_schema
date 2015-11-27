require 'test_helper'

module Sequel
  module Schema
    class CreateTableGenerator
      def ==(other)
        other_db = other.instance_variable_get(:@db)

        (columns == other.columns &&
         constraints == other.constraints &&
         indexes == other.indexes &&
         @db.serial_primary_key_options == other_db.serial_primary_key_options)
      end
    end
  end
end

class PluginTest < BaseTest
  def before_all
    @db = Sequel::Database.connect(ENV['DB_URL'])
    Sequel::Model.plugin(ModelSchema::Plugin)
    Sequel::Model.db = @db
    @db.cache_schema = false
  end

  def around
    @db.transaction(:rollback => :always, :auto_savepoint => true) {super}
  end

  def create_simple_table
    table_name = :simple
    @db.create_table(table_name) do
      String :name, :size => 50
      Integer :value, :null => false
      index :name, :unique => true
    end

    table_name
  end

  def test_simple_schema
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema do
        String :name, :size => 50
        Integer :value, :null => false
        index :name, :unique => true
      end
    end
  end

  def test_simple_schema_type_aliases
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema do
        varchar :name, :size => 50
        column :value, 'integer', :null => false
        index :name, :unique => true
      end
    end
  end

  def test_simple_schema_no_indexes
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema(:no_indexes => true) do
        varchar :name, :size => 50
        column :value, 'integer', :null => false
      end
    end
  end

  def test_disable_simple_schema
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema(:disable => true) {}
    end
  end

  def test_disable_simple_schema_env
    ENV[ModelSchema::DISABLE_MODEL_SCHEMA_KEY] = '1'
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema {}
    end
    ENV.delete(ModelSchema::DISABLE_MODEL_SCHEMA_KEY)
  end

  def test_simple_schema_extra_col
    simple_table = create_simple_table

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema {}
      end
    rescue error_class => error
      generator = Class.new(Sequel::Model(simple_table)).send(:table_generator)
      diffs = [create_extra_diff(field_columns, generator, :name => :name),
               create_extra_diff(field_columns, generator, :name => :value),
               create_extra_diff(field_indexes, generator, :columns => [:name])]

      diffs.each {|d| assert_includes error.schema_diffs, d}
      assert_equal diffs.length, error.schema_diffs.length
    else
      flunk 'Extra column not detected'
    end
  end

  def test_simple_schema_missing_col
    simple_table = create_simple_table

    table_proc = proc do
      String :name, :size => 50
      Integer :value, :null => false
      index :name, :unique => true

      TrueClass :is_valid, :default => true
      DateTime :completed_at
      index :value, :where => {:is_valid => true}
    end
    generator = @db.create_table_generator(&table_proc)

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema(&table_proc)
      end
    rescue error_class => error
      diffs = [create_missing_diff(field_columns, generator, :name => :is_valid),
               create_missing_diff(field_columns, generator, :name => :completed_at),
               create_missing_diff(field_indexes, generator, :columns => [:value])]

      diffs.each {|d| assert_includes error.schema_diffs, d}
      assert_equal diffs.length, error.schema_diffs.length
    else
      flunk 'Missing column not detected'
    end
  end

  def test_simple_schema_mismatch_col
    simple_table = create_simple_table

    table_proc = proc do
      String :name, :size => 50, :default => true
      primary_key :value
      index :name
    end
    exp_generator = @db.create_table_generator(&table_proc)

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema(&table_proc)
      end
    rescue error_class => error
      db_generator = Class.new(Sequel::Model(simple_table)).send(:table_generator)
      diffs = [create_mismatch_diff(field_columns, db_generator, exp_generator,
                                    :name => :name),
               create_mismatch_diff(field_columns, db_generator, exp_generator,
                                    :name => :value),
               create_mismatch_diff(field_indexes, db_generator, exp_generator,
                                    :columns => [:name])]

      diffs.each {|d| assert_includes error.schema_diffs, d}
      assert_equal diffs.length, error.schema_diffs.length
    else
      flunk 'Extra column not detected'
    end
  end

  def create_complex_table
    # other table for referencing
    @db.create_table(:others) do
      primary_key :id
      Integer :value
    end

    table_name = :complex
    @db.create_table(table_name) do
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

  def test_complex_schema
    complex_table = create_complex_table

    Class.new(Sequel::Model(complex_table)) do
      model_schema do
        primary_key :id
        foreign_key :other_id, :others, :null => false, :on_delete => :cascade

        String :name
        String :location, :fixed => true, :size => 50
        String :legal_name, :size => 200
        String :advisor, :text => true

        BigDecimal :amount, :size => [10, 0]
        Integer :value, :null => false

        column :advisors, 'character varying(255)[]', :null => false
        column :interests, 'text[]', :null => false

        Time :created_at, :null => false
        Time :updated_at, :only_time => true

        TrueClass :is_right

        index [:other_id, :name]
        index :value, :unique => true
        index :interests
      end
    end
  end

  def test_complex_schema_many_errors_integration
    complex_table = create_complex_table

    table_proc = proc do
      primary_key :id, :serial => true  # correct; serial is implied
      # wrong table name
      foreign_key :other_id, :some_others, :null => false, :on_delete => :cascade

      String :name  # correct
      String :location  # missing all attributes
      # db has extra legal_name field
      String :advisor  # missing :text => true, but it's equivalent for postgres
      Float :pi  # db is missing field

      # wrong name; missing field + extra field
      BigDecimal :amt, :size => [10, 0]
      Integer :value, :null => false  # correct

      column :advisors, 'text[]', :null => false  # wrong type
      # db has extra interests field
      TrueClass :is_missing, :null => false  # db is missing field

      Time :created_at, :null => true  # :null => true instead of false
      Time :updated_at  # not only_time

      # correct w/ equivalent type and normal default
      FalseClass :is_right, :default => nil

      index [:other_id, :name], :unique => true  # incorrectly unique
      index [:other_id, :name]  # correct index, same columns as above
      index :amount, :name => :int_index  # same name as other index
      index :advisor  # db is missing index

      # db has extra value index
    end
    exp_generator = @db.create_table_generator(&table_proc)

    begin
      Class.new(Sequel::Model(complex_table)) do
        model_schema(&table_proc)
      end
    rescue error_class => error
      db_generator = Class.new(Sequel::Model(complex_table)).send(:table_generator)
      complex_table_str = complex_table.to_s

      parts = [complex_table_str, 'extra columns',
               # within sub-arrays, any order is OK
               [dump_column(db_generator, :legal_name),
                dump_column(db_generator, :amount),
                dump_column(db_generator, :interests)],

               complex_table_str, 'missing columns',
               [dump_column(exp_generator, :pi),
                dump_column(exp_generator, :amt),
                dump_column(exp_generator, :is_missing)],

               complex_table_str, 'mismatched columns',
               [dump_column(db_generator, :other_id),
                dump_column(exp_generator, :other_id),
                dump_column(db_generator, :location),
                dump_column(exp_generator, :location),
                dump_column(db_generator, :advisors),
                dump_column(exp_generator, :advisors),
                dump_column(db_generator, :created_at),
                dump_column(exp_generator, :created_at),
                dump_column(db_generator, :updated_at),
                dump_column(exp_generator, :updated_at)],

               complex_table_str, 'extra indexes',
               dump_index(db_generator, :value),

               complex_table_str, 'missing indexes',
               # refers to first, incorrectly unique index
               [dump_index(exp_generator, [:other_id, :name]),
                dump_index(exp_generator, :advisor)],

               complex_table_str, 'mismatched indexes',
               [dump_index(db_generator, :interests),
                dump_index(exp_generator, :amount)],
      
               'disable', ModelSchema::DISABLE_MODEL_SCHEMA_KEY, '=1']

      assert_includes_with_order error.message, parts
    else
      flunk 'Numerous errors not detected'
    end
  end
end
