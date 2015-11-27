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
    end

    table_name
  end

  def test_simple_schema
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema do
        String :name, :size => 50
        Integer :value, :null => false
      end
    end
  end

  def test_simple_schema_type_aliases
    simple_table = create_simple_table

    Class.new(Sequel::Model(simple_table)) do
      model_schema do
        varchar :name, :size => 50
        column :value, 'integer', :null => false
      end
    end
  end

  def test_simple_schema_extra_col
    simple_table = create_simple_table

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema {}
      end
    rescue error_class => error
      generator = @db.send(:dump_table_generator, simple_table)
      schema_diffs = error.schema_diffs

      assert_includes schema_diffs, create_extra_diff(field_columns, generator,
                                                      :name => :name)
      assert_includes schema_diffs, create_extra_diff(field_columns, generator,
                                                      :name => :value)
      assert_equal schema_diffs.length, 2
    else
      flunk 'Extra column not detected'
    end
  end

  def test_simple_schema_missing_col
    simple_table = create_simple_table

    table_proc = proc do
      String :name, :size => 50
      Integer :value, :null => false

      TrueClass :is_valid, :default => true
      DateTime :completed_at
    end
    generator = @db.create_table_generator(&table_proc)

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema(&table_proc)
      end
    rescue error_class => error
      schema_diffs = error.schema_diffs

      assert_includes schema_diffs, create_missing_diff(field_columns, generator,
                                                        :name => :is_valid)
      assert_includes schema_diffs, create_missing_diff(field_columns, generator,
                                                        :name => :completed_at)
    else
      flunk 'Missing column not detected'
    end
  end

  def test_simple_schema_mismatch_col
    simple_table = create_simple_table

    table_proc = proc do
      String :name, :size => 50, :default => true
      primary_key :value
    end
    exp_generator = @db.create_table_generator(&table_proc)

    begin
      Class.new(Sequel::Model(simple_table)) do
        model_schema(&table_proc)
      end
    rescue error_class => error
      db_generator = @db.send(:dump_table_generator, simple_table)
      schema_diffs = error.schema_diffs

      assert_includes schema_diffs, create_mismatch_diff(field_columns, db_generator,
                                                         exp_generator, :name => :name)
      assert_includes schema_diffs, create_mismatch_diff(field_columns, db_generator,
                                                         exp_generator, :name => :value)
      assert_equal schema_diffs.length, 2
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
      Integer :value, :null => false

      column :advisors, 'varchar(255)[]', :null => false
      column :interests, 'text[]', :null => false

      Time :created_at, :null => false
      Time :updated_at, :only_time => true

      unique [:other_id, :name]
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

        unique [:other_id, :name]
      end
    end
  end
end
