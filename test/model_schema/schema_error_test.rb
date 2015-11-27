require 'test_helper'

class SchemaErrorTest < BaseTest
  def setup
    @db = Sequel::Database.new
    @db.extension(:schema_dumper)
    @table_name = 'schema_error_table'
  end

  def create_table_generator
    Sequel::Schema::CreateTableGenerator.new(@db) do
      primary_key :id
      foreign_key :organization_id, :organizations, :null => false, 
                                                    :key => [:id],
                                                    :on_delete => :cascade

      Integer :type
      String :first_name, :text => true, :null => false
      column :emails, 'text[]', :null => false
      DateTime :created_at, :null => false
      DateTime :updated_at

      index :type
      index :created_at, :name => :created_at_index
      index [:first_name, :emails], :unique => true, :type => :gin,
                                    :where => {:type => 1}
    end
  end

  def test_dump_single_column
    generator = create_table_generator
    assert_equal 'Integer :type', dump_column(generator, :type)
  end

  def test_dump_single_column_with_options
    generator = create_table_generator
    assert_equal 'String :first_name, :text=>true, :null=>false',
                 dump_column(generator, :first_name)
  end

  def test_dump_single_foreign_key
    generator = create_table_generator
    fk_str = %(foreign_key :organization_id, :organizations, :null=>false, 
               :key=>[:id], :on_delete=>:cascade).gsub(/\n\s+/, '')
    assert_equal fk_str, dump_column(generator, :organization_id)
  end

  def test_dump_single_primary_key
    generator = create_table_generator
    assert_equal 'primary_key :id', dump_column(generator, :id)
  end

  def test_dump_single_custom_type
    generator = create_table_generator
    assert_equal 'column :emails, "text[]", :null=>false',
                 dump_column(generator, :emails)
  end

  def test_dump_single_index
    generator = create_table_generator
    assert_equal 'index [:type]', dump_index(generator, :type)
  end

  def test_dump_single_index_with_options
    generator = create_table_generator
    assert_equal 'index [:created_at], :name=>:created_at_index',
                 dump_index(generator, :created_at)
  end

  def test_dump_single_index_complex
    generator = create_table_generator
    index_str = %(index [:first_name, :emails], :unique=>true, :type=>:gin, 
                  :where=>{:type=>1}).gsub(/\n\s+/, '')
    assert_equal index_str, dump_index(generator, [:first_name, :emails])
  end

  def test_col_extra
    generator = create_table_generator
    schema_diffs = [create_extra_diff(field_columns, generator, :name => :created_at),
                    create_extra_diff(field_columns, generator, :name => :first_name),
                    create_extra_diff(field_indexes, generator,
                                      :columns => [:type]),
                    create_extra_diff(field_indexes, generator,
                                      :columns => [:created_at])]

    message = schema_error(schema_diffs).to_s
    parts = [@table_name, 'extra columns',
             [dump_column(generator, :created_at),
              dump_column(generator, :first_name)],

             @table_name, 'extra indexes',
             [dump_index(generator, :type),
              dump_index(generator, :created_at)],

             'disable', ModelSchema::DISABLE_MODEL_SCHEMA_KEY, '=1']

    assert_includes_with_order message, parts
  end

  def test_col_missing
    generator = create_table_generator
    schema_diffs = [create_missing_diff(field_columns, generator, :name => :type),
                    create_missing_diff(field_columns, generator, :name => :updated_at),
                    create_missing_diff(field_indexes, generator,
                                        :columns => [:created_at]),
                    create_missing_diff(field_indexes, generator,
                                        :columns => [:first_name, :emails])]

    message = schema_error(schema_diffs).to_s
    parts = [@table_name, 'missing columns',
             [dump_column(generator, :type),
              dump_column(generator, :updated_at)],

             @table_name, 'missing indexes',
             [dump_index(generator, :created_at),
              dump_index(generator, [:first_name, :emails])],

             'disable', ModelSchema::DISABLE_MODEL_SCHEMA_KEY, '=1']

    assert_includes_with_order message, parts
  end

  def create_exp_table_generator
    Sequel::Schema::CreateTableGenerator.new(@db) do
      foreign_key :organization_id, :org
      String :emails, :text => true, :null => false, :unique => true
      DateTime :created_at

      index :updated_at, :name => :created_at_index
      index [:first_name, :emails], :unique => true, :where => {:type => 2}
    end
  end

  def test_col_mismatch
    generator = create_table_generator
    exp_generator = create_exp_table_generator

    schema_diffs = [create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :organization_id),
                    create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :emails),
                    create_mismatch_diff(field_indexes, generator, exp_generator,
                                         :name => :created_at_index),
                    create_mismatch_diff(field_indexes, generator, exp_generator,
                                         :columns => [:first_name, :emails])]

    message = schema_error(schema_diffs).to_s
    parts = [@table_name, 'mismatched columns',
             [dump_column(generator, :organization_id),
              dump_column(exp_generator, :organization_id),
              dump_column(generator, :emails),
              dump_column(exp_generator, :emails)],

             @table_name, 'mismatched indexes',
             [dump_index(generator, :created_at),
              dump_index(exp_generator, :updated_at),
              dump_index(generator, [:first_name, :emails]),
              dump_index(exp_generator, [:first_name, :emails])],

             'disable', ModelSchema::DISABLE_MODEL_SCHEMA_KEY, '=1']

    assert_includes_with_order message, parts
  end

  def test_col_all
    generator = create_table_generator
    exp_generator = create_exp_table_generator

    schema_diffs = [create_extra_diff(field_columns, generator, :name => :type),
                    create_extra_diff(field_indexes, generator,
                                      :columns => [:created_at]),
                    create_missing_diff(field_columns, exp_generator,
                                        :name => :organization_id),
                    create_missing_diff(field_columns, generator,
                                        :name => :first_name),
                    create_mismatch_diff(field_columns, generator, exp_generator,
                                         :name => :created_at),
                    create_mismatch_diff(field_indexes, generator, exp_generator,
                                         :columns => [:first_name, :emails])]

    message = schema_error(schema_diffs).to_s
    parts = [@table_name, 'extra columns',
             dump_column(generator, :type),

             @table_name, 'missing columns',
             [dump_column(exp_generator, :organization_id),
              dump_column(generator, :first_name)],

             @table_name, 'mismatched columns',
             [dump_column(generator, :created_at),
              dump_column(exp_generator, :created_at)],

             @table_name, 'extra indexes',
             dump_index(generator, :created_at),

             @table_name, 'mismatched indexes',
             [dump_index(generator, [:first_name, :emails]),
              dump_index(exp_generator, [:first_name, :emails])],

             'disable', ModelSchema::DISABLE_MODEL_SCHEMA_KEY, '=1']

    assert_includes_with_order message, parts
  end
end
